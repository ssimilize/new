--[[
	ShowtimeClient (update 1.5): the Wardrobe, accessory models and a Monster Contest,
	played through the real client (ClientHarness) like players would.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local C = Config.Contests

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

	local function pickInMonsters(c, id: string)
		expect(c.kernel.Router:Current()).toBe("Monsters")
		local cell = c:Screen("Monsters"):FindFirstChild(id, true)
		expect(cell ~= nil).toBe(true)
		c:Click(cell:FindFirstChild("Tap"))
		c:Advance(1)
	end

	describe("Wardrobe", function()
		it("buys, wears and takes off an accessory from the monster screen", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 5)
			h:System("Currency"):Add(p, "gems", 500, "test")
			local m = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 2, stage = 3 }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)

			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			c:Click(detail:FindFirstChild("Style", true))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Wardrobe")
			local screen = c:Screen("Wardrobe")
			expect(c:HasText("No spare head accessories", screen)).toBe(true)

			c:Click(c:Button("Shop", screen))
			c:Advance(0.5)
			local hat = screen:FindFirstChild("Acc_top_hat", true)
			expect(hat ~= nil).toBe(true)
			c:Click(hat:FindFirstChild("Buy"))
			c:Advance(1)
			expect(h:Section(p, "Accessories").owned.top_hat).toBe(1)

			c:Click(c:Button("Owned", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("Acc_top_hat", true):FindFirstChild("Wear"))
			c:Advance(1)
			expect(m.acc.head).toBe("top_hat")
			-- The 3D preview wears it.
			expect(screen:FindFirstChild("Preview", true):FindFirstChild("Acc_head", true) ~= nil).toBe(true)
			expect(c:HasText("Top Hat", screen:FindFirstChild("Slot_head", true))).toBe(true)

			c:Click(screen:FindFirstChild("Slot_head", true):FindFirstChild("TakeOff"))
			c:Advance(1)
			expect(m.acc).toBeNil()
			expect(h:Section(p, "Accessories").owned.top_hat).toBe(1)
			c:Close("Wardrobe")
			expectClean(c)
		end)

		it("builds every accessory on every body shape", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local Appearance = t.Shared("Logic.Appearance")
			local archetypes = {}
			for _, line in Config.Species.Lines do
				if not archetypes[line.archetype] then
					archetypes[line.archetype] = line.id
				end
			end
			local built = 0
			for _, lineId in archetypes do
				for _, acc in Config.Accessories.List do
					local ap = Appearance.Preview(lineId, 3)
					ap.acc = { [acc.slot] = acc.id }
					local model = MonsterModel.Build(ap)
					expect(model:FindFirstChild("Acc_" .. acc.slot, true) ~= nil).toBe(true)
					model:Destroy()
					built += 1
				end
			end
			expect(built >= #Config.Accessories.List).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Monster Contest client", function()
		it("enters, walks the runway on the stage, votes and shows the podium", function()
			local show = 2900001
			local h = TestKernel.new({ systems = allSystems(), startTime = show * C.CycleSeconds + 3 })
			local a = h:Join(8801, "Ava")
			local b = h:Join(8802, "Bo")
			levelTo(h, a, 8)
			levelTo(h, b, 8)
			local ma = h:System("Monsters"):Create(a, { line = "cindlet", rarity = 2, stage = 3 }, "test", true)
			local ca = ClientHarness.new(h, a)
			local cb = ClientHarness.new(h, b)
			ca:Advance(1)
			cb:Advance(1)

			local screen = ca:Open("Contests")
			ca:Advance(1)
			expect(ca:HasText(C.ThemeFor(show).name, screen)).toBe(true)
			expect(ca:HasText("Entries close in", screen)).toBe(true)
			ca:Click(screen:FindFirstChild("EnterButton", true))
			ca:Advance(0.5)
			pickInMonsters(ca, ma.id)
			expect(h:Session(a, "Contests").entered).toBe(ma.id)
			expect(ca.kernel.Router:Current()).toBe("Contests")
			expect(screen:FindFirstChild("Withdraw", true) ~= nil).toBe(true)

			-- Bo watches the runway and votes 5 stars.
			local watch = cb:Open("Contests")
			cb:Advance(C.EntrySeconds)
			ca:Advance(0.1)
			expect(h:Client(b).global.Contests.state).toBe("runway")
			expect(ca:HasText("Your monster is on the runway!", screen)).toBe(true)
			expect(cb:HasText("Ava's", watch)).toBe(true)
			local stage = cb.world.workspace.World.Hub.Buildings.showStage
			expect(stage:FindFirstChild("RunwayMonster") ~= nil).toBe(true)
			cb:Click(watch:FindFirstChild("Star5", true))
			cb:Advance(0.5)
			expect(h:Session(b, "Contests").votes[1]).toBe(5)

			cb:Advance(C.RunwaySeconds + 1)
			ca:Advance(0.1)
			expect(h:Client(a).global.Contests.state).toBe("results")
			expect(screen:FindFirstChild("Result_1", true) ~= nil).toBe(true)
			expect(h:System("Currency"):Balance(a, "ribbons")).toBe(C.Prizes[1][1].amount)
			expect(h:System("Currency"):Balance(b, "ribbons")).toBe(1)
			expect(stage:FindFirstChild("RunwayMonster")).toBeNil()
			ca:Close("Contests")
			cb:Close("Contests")
			expectClean(ca)
			expectClean(cb)
		end)
	end)
end
