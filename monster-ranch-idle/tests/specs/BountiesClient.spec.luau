--[[
	BountiesClient (update 3.9): Expedition Bounties through the real client (ClientHarness): the
	Bounties tab's wanted posters, "Hunt" by a real click fighting the stage and marking the bounty
	done, the stage map's bounty marker, the locked and empty states, and the tab in Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

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

	-- A level 6 player who has cleared meadow stage `cleared`, with a squad that wins there.
	local function hunter(h, cleared: number)
		local p = h:Join()
		h:Section(p, "Expeditions").cleared.meadow = cleared
		levelTo(h, p, 6)
		local ids = {}
		for _, line in { "cindlet", "bubblin", "mossbun" } do
			local m = h:System("Monsters"):Create(p, { line = line, rarity = 5, stage = 3 }, "test", true)
			m.lv = 60
			table.insert(ids, m.id)
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return p
	end

	local function bounties(h, p)
		return h:Section(p, "Expeditions").bounty.list
	end

	describe("Bounties tab", function()
		it("shows three wanted posters and hunts one with a real click", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = hunter(h, 12)
			local list = bounties(h, p)
			expect(#list).toBe(3)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local Battle = c:require(c.clientFolder.UI.Screens.Parts.Battle)
			Battle.SetMode("2d")
			local screen = c:Open("Expeditions", { tab = "bounties" })
			c:Advance(0.5)
			expect(c:HasText("Wanted this week", screen)).toBe(true)
			expect(c:HasText("New bounties in", screen)).toBe(true)
			expect(c:HasText("Egg chance: up to 50%", screen)).toBe(true)
			for i, b in list do
				local card = screen:FindFirstChild("Bounty" .. i, true)
				expect(card ~= nil).toBe(true)
				expect(c:IsShown(card)).toBe(true)
				expect(c:HasText("WANTED", card)).toBe(true)
				expect(c:HasText(b.name, card)).toBe(true)
				expect(c:HasText(string.format("Whispering Meadow · Stage %d", b.stage), card)).toBe(true)
			end

			local target = list[1]
			c:Click(screen:FindFirstChild("Bounty1", true):FindFirstChild("Hunt", true))
			c:Advance(0.5)
			expect(bounties(h, p)[1].done).toBe(true)
			expect(h:Section(p, "Expeditions").bounty.count).toBe(1)
			local top = c.kernel.UI.Top
			expect(top:FindFirstChild("BattleReplay") ~= nil).toBe(true)
			c:Click(c:Button("Skip »", top))
			c:Advance(1)
			expect(c:HasText("Bounty defeated!", top)).toBe(true)
			c:Click(c:Button("Continue", top))
			c:Advance(1)

			-- Hunt switched to the stages view on the bounty's region: the other two stages carry
			-- the marker, the defeated one no longer does.
			local stages = screen:FindFirstChild("Stages", true)
			expect(c:IsShown(stages)).toBe(true)
			expect(c:HasText(string.format("Fight stage %d", target.stage), stages) or c:HasText("Fight stage", stages)).toBe(true)
			local nodes = stages:FindFirstChild("Nodes", true)
			expect(nodes:FindFirstChild("Stage" .. target.stage):FindFirstChild("Bounty")).toBeNil()
			for i = 2, 3 do
				local node = nodes:FindFirstChild("Stage" .. list[i].stage)
				expect(node:FindFirstChild("Bounty") ~= nil).toBe(true)
			end

			-- Back on the tab the poster reads as defeated.
			c:Click(c:Button("Bounties", screen))
			c:Advance(0.5)
			local done = screen:FindFirstChild("Bounty1", true)
			expect(c:HasText("Defeated", done)).toBe(true)
			expect(c:HasText("Bounties defeated this week: 1", screen)).toBe(true)
			Battle.SetMode(nil)
			expectClean(c)
		end)

		it("is locked before Level 6 and friendly when there is nothing to hunt", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Expeditions", { tab = "bounties" })
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 6", screen)).toBe(true)
			c:Close("Expeditions")
			levelTo(h, p, 6)
			c:Advance(1)
			screen = c:Open("Expeditions", { tab = "bounties" })
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 6", screen)).toBe(false)
			expect(c:HasText("No bounties yet. Clear a stage in any region and wanted monsters will show up here.", screen)).toBe(true)
			expect(screen:FindFirstChild("Bounty1", true)).toBeNil()
			expectClean(c)
		end)

		it("shows the posters in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = hunter(h, 9)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local screen = c:Open("Expeditions", { tab = "bounties" })
			c:Advance(0.5)
			expect(c:HasText("SE BUSCA", screen)).toBe(true)
			expect(c:HasText("Cazar", screen)).toBe(true)
			expect(c:HasText("Buscados de esta semana", screen)).toBe(true)
			expect(c:HasText("Probabilidad de huevo: hasta 50%", screen)).toBe(true)
			expect(c:HasText("WANTED", screen)).toBe(false)
			expectClean(c)
		end)
	end)
end
