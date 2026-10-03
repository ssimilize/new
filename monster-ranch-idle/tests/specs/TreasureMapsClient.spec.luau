--[[
	TreasureMapsClient (update 3.13 · Wild things): Treasure Maps through the real client
	(ClientHarness): the Expeditions header's "Maps" button opening the screen, the pieces' quarter
	tiles, a held map's parchment card, "Dig" by a real click → the replay → the chest and the map
	used, the locked state below Level 23, and the screen in Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.TreasureMaps")
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

	-- A Level 23 player with the Meadow cleared to stage 12 and a squad that wins there.
	local function hunter(h)
		local p = h:Join()
		h:Section(p, "Expeditions").cleared.meadow = 12
		levelTo(h, p, Config.Unlocks.Features.treasure_maps)
		local ids = {}
		for _, line in { "cindlet", "bubblin", "mossbun" } do
			local m = h:System("Monsters"):Create(p, { line = line, rarity = 6, stage = 3 }, "test", true)
			m.lv = 100
			table.insert(ids, m.id)
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return p
	end

	local function filled(screen): number
		local n = 0
		for i = 1, Config.TreasureMaps.PiecesPerMap do
			local tile = screen:FindFirstChild("Quarter" .. i, true)
			if tile and tile:GetAttribute("Filled") then
				n += 1
			end
		end
		return n
	end

	describe("Treasure Maps screen", function()
		it("opens from the Expeditions header's Maps button", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = hunter(h)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local exp = c:Open("Expeditions")
			c:Advance(0.5)
			c:Click(c:Button("Maps", exp))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("TreasureMaps")
			local screen = c:Screen("TreasureMaps")
			expect(c:HasText("Pieces: 0/4", screen)).toBe(true)
			expect(c:HasText("Your maps: 0/3", screen)).toBe(true)
			expect(c:HasText("No maps yet. Collect four pieces to make one.", screen)).toBe(true)
			expect(filled(screen)).toBe(0)
			expectClean(c)
		end)

		it("shows a held map and digs it up: Dig, the replay, the chest, the map used", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = hunter(h)
			h:System("TreasureMaps"):AddPieces(p, 6)
			local map = table.clone(h:Section(p, "TreasureMaps").maps[1])
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("TreasureMaps")
			c:Advance(0.5)
			expect(filled(screen)).toBe(2)
			expect(c:HasText("Pieces: 2/4", screen)).toBe(true)
			expect(c:HasText("Your maps: 1/3", screen)).toBe(true)
			local card = screen:FindFirstChild("Map1", true)
			expect(card ~= nil).toBe(true)
			expect(c:HasText("Whispering Meadow", card)).toBe(true)
			expect(c:HasText(string.format("Guardian power %s", Format.short(Logic.GuardianPower(map))), card)).toBe(true)
			expect(c:HasText("25% chance of a rare decor piece", card)).toBe(true)
			expect(card:FindFirstChild("Rewards", true) ~= nil).toBe(true)

			local Battle = c:require(c.clientFolder.UI.Screens.Parts.Battle)
			Battle.SetMode("2d")
			local gems = h:Section(p, "Currency").gems
			c:Click(c:Button("Dig", card))
			c:Advance(0.5)
			expect(#h:Section(p, "TreasureMaps").maps).toBe(0)
			expect(h:Section(p, "Currency").gems - gems).toBe(Config.TreasureMaps.ChestGems)
			local top = c.kernel.UI.Top
			expect(top:FindFirstChild("BattleReplay") ~= nil).toBe(true)
			c:Click(c:Button("Skip »", top))
			c:Advance(1)
			expect(c:HasText("Treasure found!", top)).toBe(true)
			c:Click(c:Button("Continue", top))
			c:Advance(1)
			expect(c:HasText("Your maps: 0/3", screen)).toBe(true)
			Battle.SetMode(nil)
			expectClean(c)
		end)

		it("is locked below Level 23", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("TreasureMaps")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 23", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the maps in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = hunter(h)
			h:System("TreasureMaps"):AddPieces(p, 4)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local exp = c:Open("Expeditions")
			c:Advance(0.5)
			expect(c:HasText("Mapas", exp)).toBe(true)
			local screen = c:Open("TreasureMaps")
			c:Advance(0.5)
			expect(c:HasText("Mapas del tesoro", screen)).toBe(true)
			expect(c:HasText("Piezas: 0/4", screen)).toBe(true)
			expect(c:HasText("Tus mapas: 1/3", screen)).toBe(true)
			expect(c:HasText("Excavar", screen)).toBe(true)
			expect(c:HasText("Pieces: 0/4", screen)).toBe(false)
			expectClean(c)
		end)
	end)
end
