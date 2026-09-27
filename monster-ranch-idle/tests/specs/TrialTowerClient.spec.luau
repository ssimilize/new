--[[
	TrialTowerClient (update 3.12 · Honey & stars): the Trial Tower through the real client
	(ClientHarness): the tower in the Market Square and its prompt opening the screen, "Fight" by a
	real click → the replay → floor 2, the Expeditions header's "Tower" button, the locked
	state, and the screen in Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local TowerLogic = t.Shared("Logic.TrialTower")
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

	-- A Level 26 player with a squad that wins the first floors.
	local function climber(h)
		local p = h:Join()
		levelTo(h, p, Config.Unlocks.Features.trial_tower)
		local ids = {}
		for _, line in { "cindlet", "bubblin", "mossbun" } do
			local m = h:System("Monsters"):Create(p, { line = line, rarity = 6, stage = 3 }, "test", true)
			m.lv = 100
			table.insert(ids, m.id)
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return p
	end

	local function promptOf(model)
		for _, d in model:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				return d
			end
		end
		return nil
	end

	describe("Trial Tower screen", function()
		it("stands in the Market Square and its prompt opens the screen; Fight climbs to floor 2", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = climber(h)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local tower = c.world.workspace.World.Hub.Buildings:FindFirstChild("trialTower")
			expect(tower ~= nil).toBe(true)
			expect(tower:GetAttribute("Screen")).toBe("TrialTower")
			expect(tower:FindFirstChild("Merlon1") ~= nil).toBe(true)
			expect(tower:FindFirstChild("RoofFront")).toBeNil()
			local prompt = promptOf(tower)
			expect(prompt ~= nil).toBe(true)
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("TrialTower")
			local screen = c:Screen("TrialTower")
			expect(c:HasText("Floor 1", screen)).toBe(true)
			expect(c:HasText("Attempts left today: 3/3", screen)).toBe(true)
			expect(c:HasText("Retry tokens: 0", screen)).toBe(true)
			expect(c:HasText("Next milestone: floor 5", screen)).toBe(true)
			expect(c:HasText("Your Expeditions squad: 3 monsters", screen)).toBe(true)
			expect(screen:FindFirstChild("Enemy1", true) ~= nil).toBe(true)
			-- Each enemy shows the power its floor scales it to (levels come from a random stage).
			local power = TowerLogic.Preview(h:Section(p, "TrialTower").week, 1).list[1].power
			expect(screen:FindFirstChild("Enemy1", true):FindFirstChild("EnemyPower").Text).toBe(
				string.format("Power %s", Format.short(power))
			)
			-- The three buttons fit their row (fixed widths ran Leaderboard past the card in Studio).
			local actions = screen:FindFirstChild("Actions", true)
			local used = 2 * 12
			for _, name in { "Fight", "Squad", "Board" } do
				used += actions:FindFirstChild(name).AbsoluteSize.X
			end
			expect(used <= actions.AbsoluteSize.X).toBe(true)

			local Battle = c:require(c.clientFolder.UI.Screens.Parts.Battle)
			Battle.SetMode("2d")
			c:Click(c:Button("Fight", screen))
			c:Advance(0.5)
			expect(h:Section(p, "TrialTower").best).toBe(1)
			local top = c.kernel.UI.Top
			expect(top:FindFirstChild("BattleReplay") ~= nil).toBe(true)
			c:Click(c:Button("Skip »", top))
			c:Advance(1)
			expect(c:HasText("Floor 1 cleared!", top)).toBe(true)
			c:Click(c:Button("Continue", top))
			c:Advance(1)
			expect(c:HasText("Floor 2", screen)).toBe(true)
			expect(c:HasText("This week's best: floor 1", screen)).toBe(true)
			Battle.SetMode(nil)
			expectClean(c)
		end)

		it("opens from the Expeditions header", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = climber(h)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Expeditions")
			c:Advance(0.5)
			c:Click(c:Button("Tower", screen))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("TrialTower")
			expectClean(c)
		end)

		it("is locked below Level 26", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("TrialTower")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 26", screen)).toBe(true)
			expect(c:HasText("Pick a squad on the Expeditions screen first", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the tower in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = climber(h)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local screen = c:Open("TrialTower")
			c:Advance(0.5)
			expect(c:HasText("Torre de pruebas", screen)).toBe(true)
			expect(c:HasText("Pelear", screen)).toBe(true)
			expect(c:HasText("Intentos restantes hoy: 3/3", screen)).toBe(true)
			expect(c:HasText("Fichas de reintento: 0", screen)).toBe(true)
			expect(c:HasText("Attempts left today: 3/3", screen)).toBe(false)
			expectClean(c)
		end)
	end)
end
