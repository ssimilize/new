--[[
	DojoClient (update 3.11): the Dojo through the real client (ClientHarness, real clicks):
	opened from Monster Detail, a technique learned (Stardust spent, the mat's countdown), the
	timer run out, Collect, and the technique shown as a chip on Monster Detail.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Format = t.Shared("Logic.Format")
	local Formulas = t.Shared("Logic.Formulas")

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

	local function clickable(gui)
		if gui:IsA("GuiButton") then
			return gui
		end
		return gui:FindFirstChildWhichIsA("GuiButton", true)
	end

	describe("Dojo", function()
		it("opens from Monster Detail, learns a technique, runs the timer, collects and shows it on Monster Detail", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, Config.Unlocks.Features.dojo)
			h:System("Currency"):Add(p, "stardust", 1000, "test")
			local M = h:System("Monsters")
			local m = M:Create(p, { stage = 3, line = "cindlet", rarity = 2, variant = 0 }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			local genesRow = detail:FindFirstChild("GenesRow", true)
			c:Click(clickable(genesRow:FindFirstChild("Dojo")))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Dojo")
			local screen = c:Screen("Dojo")
			expect(c:HasText("The training mat is free", screen)).toBe(true)
			expect(c:HasText("Technique slots: 0/1 · the 2nd opens at Bond heart 5", screen)).toBe(true)
			local row = screen:FindFirstChild("Tech_cinder_fang", true)
			expect(row ~= nil).toBe(true)
			expect(row:FindFirstChild("Level").Text).toBe("Not learned")
			expect(row:FindFirstChild("Info").Text).toBe(string.format("Lv 1 · 300 Stardust · %s", Format.duration(20 * 60)))
			expect(screen:FindFirstChild("Tech_undertow", true)).toBeNil() -- another element's technique

			c:Click(clickable(row:FindFirstChild("Train")))
			c:Advance(1.5)
			expect(h:Section(p, "Currency").stardust).toBe(700)
			expect(m.busy).toBe("dojo")
			local mat = screen:FindFirstChild("Mat", true)
			expect(mat:FindFirstChild("MatText").Text).toBe(string.format("%s is training Cinder Fang · Lv 1", Formulas.DisplayName(m)))
			local left = mat:FindFirstChild("Time").Text
			expect(left ~= "" and left ~= "Ready!").toBe(true)
			expect(screen:FindFirstChild("Result", true).Text).toBe("Training started: Cinder Fang · Lv 1")

			h:Advance(20 * 60 + 1)
			c:Advance(1.5)
			expect(mat:FindFirstChild("Time").Text).toBe("Ready!")
			c:Click(clickable(mat:FindFirstChild("Collect")))
			c:Advance(1)
			expect(m.tech).toEqual({ { id = "cinder_fang", lv = 1 } })
			expect(m.busy).toBe(false)
			expect(screen:FindFirstChild("Result", true).Text).toBe("Learned Cinder Fang · Lv 1")
			expect(row:FindFirstChild("Level").Text).toBe("Lv 1/3")

			c:Close("Dojo")
			detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			local chip = detail:FindFirstChild("Tech_cinder_fang", true)
			expect(chip ~= nil).toBe(true)
			expect(c:HasText("Cinder Fang · Lv 1", detail)).toBe(true)
			expectClean(c)
		end)
	end)
end
