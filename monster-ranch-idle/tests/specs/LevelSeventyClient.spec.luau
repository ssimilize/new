--[[
	LevelSeventyClient (update 3.2): Level 70 played through the real client (ClientHarness)
	on a 568 × 320 phone: the 5th squad slot (locked at 69, filled at 70) and a stage replay
	with 5 allies, buying pen 6 in the Ranch screen and its world prompt, and five incubator
	slots with the Extra Incubator pass.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Format = t.Shared("Logic.Format")
	local Unlocks, Economy = Config.Unlocks, Config.Economy

	local AFTER = Unlocks.LevelCaps[2].from + 3600

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
			P:AddXP(p, Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adults(h, p, n: number)
		local ids = {}
		local lines = { "cindlet", "bubblin", "mossbun", "zappip", "lumipup" }
		for i = 1, n do
			local m = h:System("Monsters"):Create(p, { line = lines[(i - 1) % #lines + 1], rarity = 5, stage = 3 }, "test", true)
			m.lv, m.stars = 45, 3
			table.insert(ids, m.id)
		end
		return ids
	end

	local function phone(h, p)
		local c = ClientHarness.new(h, p, { viewport = t.Roblox.Vector2.new(568, 320) })
		c:Advance(1)
		return c
	end

	local function uiScale(gui): number
		local node = gui
		while node do
			local scale = node:FindFirstChildOfClass("UIScale")
			if scale then
				return scale.Scale
			end
			node = node.Parent
		end
		return 1
	end

	describe("Level 70 client", function()
		it("locks the 5th squad slot at Level 69", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = AFTER })
			local p = h:Join()
			levelTo(h, p, 69)
			local c = phone(h, p)
			local screen = c:Open("Expeditions")
			c:Advance(0.5)
			local row = screen:FindFirstChild("SquadRow", true)
			expect(row:FindFirstChild("Slot4") ~= nil).toBe(true)
			local slot5 = row:FindFirstChild("Slot5")
			expect(slot5 ~= nil).toBe(true)
			expect(c:HasText("Lv 70", slot5)).toBe(true)
			expect(c:HasText("Squad  0 / 4", screen)).toBe(true)
			c:Click(slot5)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Expeditions") -- no pick mode for a locked slot
			expectClean(c)
		end)

		it("fills the 5th squad slot at Level 70 and replays a stage with 5 allies", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = AFTER })
			local p = h:Join()
			levelTo(h, p, 70)
			local ids = adults(h, p, 5)
			h:Call(p, "Expeditions.SetSquad", { ids = { ids[1], ids[2], ids[3], ids[4] } })
			local c = phone(h, p)
			local screen = c:Open("Expeditions")
			c:Advance(0.5)
			expect(c:HasText("Squad  4 / 5", screen)).toBe(true)
			local row = screen:FindFirstChild("SquadRow", true)
			c:Click(row:FindFirstChild("Slot5"))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local picker = c:Screen("Monsters")
			local cell = picker:FindFirstChild(ids[5], true)
			expect(cell ~= nil).toBe(true)
			c:Click(cell:FindFirstChild("Tap")) -- one-monster pick mode: a tap picks
			c:Advance(1)
			expect(h:Section(p, "Expeditions").squad).toEqual(ids)
			screen = c:Screen("Expeditions")
			expect(c:HasText("Squad  5 / 5", screen)).toBe(true)

			c:Click(c:Button("Fight stage 1", screen))
			c:Advance(0.5)
			local viewer = c.kernel.UI.Top:FindFirstChild("BattleReplay")
			expect(viewer ~= nil).toBe(true)
			local allyRow
			for i = 1, 5 do
				local unit = viewer:FindFirstChild("a" .. i, true)
				expect(unit ~= nil).toBe(true)
				allyRow = unit.Parent
			end
			expect(viewer:FindFirstChild("a6", true)).toBeNil()
			-- The row is a horizontal list: 5 slots plus gaps must fit its width on the phone.
			local width, n = 0, 0
			for _, child in allyRow:GetChildren() do
				if child:IsA("GuiObject") then
					width += child.Size.X.Offset
					n += 1
				end
			end
			local gap = allyRow:FindFirstChildOfClass("UIListLayout").Padding.Offset
			expect(n).toBe(5)
			local needed = (width + gap * (n - 1)) * uiScale(allyRow)
			expect(needed <= allyRow.AbsoluteSize.X).toBe(true)
			c:Click(c:Button("Skip ▸▸", c.kernel.UI.Top)) -- not a bare "Skip": a title like "vs Sky Skipper" matches it
			c:Advance(1)
			expectClean(c)
		end)

		it("buys pen 6 in the Ranch screen and gets its world prompt", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = AFTER })
			local p = h:Join()
			levelTo(h, p, 66)
			h:System("Currency"):Add(p, "coins", 2e10, "test")
			for _ = 2, 5 do
				h:Call(p, "Ranch.BuyPen")
				h:Advance(1)
			end
			local c = phone(h, p)

			local function penPrompt(action: string)
				for _, d in c.world.workspace:GetDescendants() do
					if d:IsA("ProximityPrompt") and d.ActionText == action and (action ~= "Manage" or d.ObjectText == "Pen 6") then
						local pen = d:FindFirstAncestor("Pen6")
						if pen then
							return d
						end
					end
				end
				return nil
			end
			expect(penPrompt("Build Pen") ~= nil).toBe(true)

			local screen = c:Open("Ranch")
			c:Advance(0.5)
			c:Click(c:Button("+ Pen 6", screen))
			c:Advance(0.5)
			expect(c:HasText("Pen 6", screen)).toBe(true)
			expect(c:HasText("Build Pen 6", screen)).toBe(true)
			c:Click(c:Button(string.format("%s coins", Format.short(Economy.Pens.buyCost[6])), screen))
			c:Advance(1)
			expect(#h:Section(p, "Ranch").pens).toBe(6)
			expect(c:Button("Pen 6", screen) ~= nil).toBe(true)
			expect(c:HasText("+ Pen 7", screen)).toBe(false)
			c:Close("Ranch")
			c:Advance(1)

			local prompt = penPrompt("Manage")
			expect(prompt ~= nil).toBe(true)
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Ranch")
			expectClean(c)
		end)

		it("shows five incubator slots with the Extra Incubator pass", function()
			local M = Config.Monetization
			local saved = M.PassByKey.extraIncubator.gamePassId
			M.PassByKey.extraIncubator.gamePassId = 9301
			local ok, err = pcall(function()
				local h = TestKernel.new({ systems = allSystems(), startTime = AFTER })
				h.adapters.ownedPasses[6201] = { [9301] = true }
				local p = h:Join(6201)
				levelTo(h, p, 62)
				local eggIds = h:System("Eggs"):Add(p, "meadow", "test", 2)
				local c = phone(h, p)
				expect(c:Store("session.Eggs.slotCount")).toBe(5)
				local screen = c:Open("Incubators")
				c:Advance(0.5)
				for i = 1, Economy.Incubators.maxSlots do
					local slot = screen:FindFirstChild("Slot" .. i, true)
					expect(slot ~= nil).toBe(true)
					expect(slot:FindFirstChild("Lock")).toBeNil()
				end
				expect(c:HasText("Incubator 5", screen)).toBe(true)
				local slot5 = screen:FindFirstChild("Slot5", true)
				c:Click(c:Button("Place egg", slot5))
				c:Advance(0.3)
				c:Click(screen:FindFirstChild("meadow", true):FindFirstChild("Tap"))
				c:Advance(1)
				expect(h:Section(p, "Eggs").slots[5].egg).toBe(eggIds[1])
				expectClean(c)
			end)
			M.PassByKey.extraIncubator.gamePassId = saved
			if not ok then
				error(err, 0)
			end
		end)
	end)
end
