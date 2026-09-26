--[[
	TitanicClient (glow-up W): the Titanic tier and limited editions through the real client. The
	TITANIC and "#1/500" chips on MonsterDetail and on the value cards (Util.tagChips: the trade
	window, Market and Breeding), the Huge / Titanic odds in the egg shop, a pen model capped at
	PenScale with the Titanic attribute (deeper cry) and the "#1/500" tag at its feet.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Format = t.Shared("Logic.Format")
	local Titanic = t.Shared("Logic.Titanic")

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
		local problems = c:Problems({ "Infinite yield possible" })
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function boot()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		h:Section(p, "Quests").tutorial.step = #Config.Quests.Tutorial + 1
		h:System("Progression"):AddXP(p, 1e6, "test")
		local m = h:System("Monsters"):Create(p, { line = "lanternling", rarity = 3, titanic = true }, "hatch", true)
		local c = ClientHarness.new(h, p)
		c:Advance(2)
		return h, p, c, m
	end

	describe("Titanic client", function()
		it("shows TITANIC and the edition number on MonsterDetail and the value cards", function()
			local h, p, c, m = boot()
			expect(m.titanic).toBe(true)
			expect(m.ltdNo).toBe(1)
			local size = Config.Editions.ByLine.lanternling.size
			local label = string.format("#1/%d", size)
			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			expect(c:HasText("TITANIC", detail)).toBe(true)
			expect(c:HasText(label, detail)).toBe(true)
			expect(c:HasText("HUGE", detail)).toBe(false) -- Titanic replaces the Huge tag
			c:Close("MonsterDetail")

			-- The value card (trade window, Market, Breeding) from the same Appearance.
			local Util = c:require(c.clientFolder.UI.Screens.Parts.Util)
			local holder = c:require(c.clientFolder.UI.Create).New("Frame", { Name = "CardProbe", Parent = c.playerGui })
			Util.tagChips(h:System("Monsters"):Appearance(p, m.id), holder)
			expect(c:HasText("TITANIC", holder)).toBe(true)
			expect(c:HasText(label, holder)).toBe(true)
			local lines = {}
			for _, line in Util.valueLines(h:System("Monsters"):Appearance(p, m.id)) do
				table.insert(lines, line.text)
			end
			expect(table.concat(lines, "\n")).toContain("Titanic")
			expect(table.concat(lines, "\n")).toContain(string.format("Limited edition #1 of %d", size))
			holder:Destroy()
			expectClean(c)
		end)

		it("shows the Huge and Titanic odds with an egg's odds", function()
			local _, _, c = boot()
			local shop = c:Open("EggShop")
			c:Advance(0.5)
			local odds = Titanic.Odds()
			local text = string.format("Huge %s · Titanic %s", Format.percent(odds.huge, 2), Format.percent(odds.titanic, 2))
			expect(c:HasText(text, shop)).toBe(true)
			expectClean(c)
		end)

		it("caps a Titanic in its pen and tags it with its number", function()
			local h, p, c, m = boot()
			if m.loc ~= "pen" then
				h:Call(p, "Ranch.Assign", { id = m.id, pen = 1 })
			end
			c:Advance(3)
			local world = c.kernel:GetController("World")
			local model = world.MonsterModel(p.UserId, m.id)
			expect(model ~= nil).toBe(true)
			expect(model:GetAttribute("Titanic")).toBe(true)
			local ordinary = h:System("Monsters")
				:Create(p, { line = "lanternling", rarity = 3, weight = Config.Species.ById.lanternling.weight }, "test", true)
			if ordinary.loc ~= "pen" then
				h:Call(p, "Ranch.Assign", { id = ordinary.id, pen = 1 })
			end
			c:Advance(3)
			local plain = world.MonsterModel(p.UserId, ordinary.id)
			expect(plain ~= nil).toBe(true)
			local ratio = model:GetAttribute("Height") / plain:GetAttribute("Height")
			expect(math.abs(ratio - Config.Titanic.PenScale) < 0.05).toBe(true)
			local tag = nil
			for _, gui in c:Descendants(c.playerGui) do
				if gui:IsA("BillboardGui") and gui.Name == "EditionPlate" then
					tag = gui
				end
			end
			expect(tag ~= nil and tag.Adornee ~= nil).toBe(true)
			expect(c:HasText(string.format("#1/%d", Config.Editions.ByLine.lanternling.size), tag)).toBe(true)
			expectClean(c)
		end)
	end)
end
