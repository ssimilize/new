--[[
	DigSiteClient (update 3.11 · Seasons & secrets): the Dig Site through the real client
	(ClientHarness): the "Dig" prompt on the sand pit's rack opens the screen, Start a dig, tap an
	empty tile (a hint) and the find's tile (the reveal), reopening resumes the dig, the Codex
	Fossils tab, the locked site before Level 16 and Spanish text.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.DigSite")

	local Cfg = Config.DigSite

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

	local function digPrompt(c)
		for _, d in c.world.workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.ActionText == "Dig" then
				return d
			end
		end
		return nil
	end

	-- Points the player's next dig at one whose first find is a new fossil piece.
	local function rig(h, p)
		local s = h:Section(p, "DigSite")
		s.secret = 424242
		for n = 1, 5000 do
			local finds = Logic.Layout(Logic.Seed(p.UserId, n, s.secret))
			if finds[1].kind == "piece" then
				s.n = n - 1
				return finds
			end
		end
		error("no dig matched")
	end

	describe("Dig Site", function()
		it("opens from the prompt, digs a hint and a fossil piece, resumes and shows the Fossils tab", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 16)
			local finds = rig(h, p)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local prompt = digPrompt(c)
			expect(prompt ~= nil).toBe(true)
			expect(prompt:FindFirstAncestor("DigSite") ~= nil).toBe(true)
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("DigSite")
			local screen = c:Screen("DigSite")
			expect(c:HasText(string.format("Free digs today: %d / %d · Shovels: 0", Cfg.FreeDigs, Cfg.FreeDigs), screen)).toBe(true)

			c:Click(screen:FindFirstChild("StartDig", true))
			c:Advance(0.5)
			expect(c:HasText(string.format("Taps left: %d / %d", Cfg.Taps, Cfg.Taps), screen)).toBe(true)
			expect(screen:FindFirstChild("StartDig", true)).toBeNil()

			-- An empty tile tells you how close the find is.
			local empty
			for n = 1, Cfg.Tiles do
				local taken = false
				for _, f in finds do
					taken = taken or f.tile == n
				end
				if not taken then
					empty = n
					break
				end
			end
			c:Click(screen:FindFirstChild("Tile_" .. empty, true))
			c:Advance(0.5)
			local hint = Logic.Hint(finds, {}, empty)
			local tile = screen:FindFirstChild("Tile_" .. empty, true)
			expect(tile:GetAttribute("Dug")).toBe(true)
			expect(tile.Text).toBe(Logic.HintText(hint))
			expect(c:HasText(string.format("Nothing here · %s", Logic.HintText(hint)), screen)).toBe(true)

			-- Closing and reopening resumes the same dig.
			c:Close("DigSite")
			c:Advance(0.3)
			screen = c:Open("DigSite")
			c:Advance(0.5)
			expect(c:HasText(string.format("Taps left: %d / %d", Cfg.Taps - 1, Cfg.Taps), screen)).toBe(true)
			expect(screen:FindFirstChild("Tile_" .. empty, true):GetAttribute("Dug")).toBe(true)

			-- The find's tile reveals the piece.
			local f = finds[1]
			c:Click(screen:FindFirstChild("Tile_" .. f.tile, true))
			c:Advance(0.5)
			local found = screen:FindFirstChild("Tile_" .. f.tile, true)
			expect(found:GetAttribute("Kind")).toBe("piece")
			expect(found.Text).toBe(Cfg.PieceById[f.piece].name)
			expect(c:HasText(string.format("New fossil piece: %s · %s", Cfg.ById[f.fossil].name, Cfg.PieceById[f.piece].name), screen)).toBe(
				true
			)
			expect(h:Section(p, "DigSite").pieces[f.fossil][f.piece]).toBe(true)

			-- The Fossils button opens the Codex's Fossils tab with the piece.
			c:Click(screen:FindFirstChild("Fossils", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Codex")
			local codex = c:Screen("Codex")
			local card = codex:FindFirstChild("Fossil_" .. f.fossil, true)
			expect(card ~= nil).toBe(true)
			expect(c:HasText(Cfg.ById[f.fossil].name, card)).toBe(true)
			expect(card:FindFirstChild("Piece_" .. f.piece, true):GetAttribute("Found")).toBe(true)
			expect(c:HasText(string.format("Fossils · 0 / %d complete · 1 pieces", #Cfg.Fossils), codex)).toBe(true)
			expect(codex:FindFirstChild("fossil_2", true) ~= nil).toBe(true)
			expectClean(c)
		end)

		it("shows the site locked before Level 16", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("DigSite")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 16", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the site in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 16)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			c:Open("DigSite")
			c:Advance(0.5)
			expect(c:HasText("Sitio de excavación")).toBe(true)
			expectClean(c)
		end)
	end)
end
