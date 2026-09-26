--[[
	CodexClient (glow-up O): Codex milestones claimed through the screen and its HUD badge, the
	walk-in Codex Museum's model cap and pooling, and the shared Hall of Fame plaza, driven through
	the real client (ClientHarness).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local CFrame = t.Roblox.CFrame

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

	local function discover(h, p, formIds: { string })
		local codex = h:Section(p, "Monsters").codex
		for _, formId in formIds do
			local info = Config.Species.FormById[formId]
			local entry = codex[info.line.id] or { forms = {}, variants = { normal = true }, count = 1 }
			codex[info.line.id] = entry
			entry.forms[formId] = true
		end
	end

	local function codexBadge(c): boolean
		for _, gui in c:Descendants(c.kernel.UI.Hud) do
			if gui.Name == "Codex" then
				local badge = gui:FindFirstChild("Badge", true)
				return badge ~= nil and badge.Visible
			end
		end
		error("no Codex button on the HUD")
	end

	describe("Codex client", function()
		it("shows the HUD badge and claims a milestone through the Milestones tab", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			discover(h, p, { "cindlet", "kindlefox", "blazefang" })
			p = h:Rejoin(p, 5) -- the next session loads the discoveries
			local c = ClientHarness.new(h, p)
			c:Advance(3)
			expect(codexBadge(c)).toBe(true)
			local screen = c:Open("Codex", { tab = "milestones" })
			c:Advance(1)
			expect(c:HasText("Find 3 Ember forms", screen)).toBe(true)
			local card = screen:FindFirstChild("el_ember_3", true)
			expect(card ~= nil).toBe(true)
			local gems = h:Section(p, "Currency").gems
			c:Click(c:Button("Claim", card))
			c:Advance(1)
			expect(h:Section(p, "Codex").claimed.el_ember_3 ~= nil).toBe(true)
			expect(h:Section(p, "Currency").gems).toBe(gems + Config.Codex.Gems.elementStep[1])
			card = screen:FindFirstChild("el_ember_3", true)
			expect(c:HasText("Claimed", card)).toBe(true)
			expect(codexBadge(c)).toBe(false)
			-- The Species tab is still the default view.
			c:Click(c:Button("Species", screen))
			c:Advance(1)
			expect(c:HasText("Tap a species to see its evolutions.", screen)).toBe(true)
			c:Close("Codex")
			expectClean(c)
		end)

		it("builds at most the cap of museum models near the camera and pools the rest", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local forms = {}
			for _, def in Config.Species.Lines do
				if not def.event then
					table.insert(forms, def.forms[1].id)
				end
			end
			discover(h, p, forms)
			p = h:Rejoin(p, 5)
			local c = ClientHarness.new(h, p)
			local Museum = c:require(c.clientFolder.Controllers.CodexMuseum)
			local camera = c.world.game:GetService("Workspace").CurrentCamera
			local M = Config.Codex.Museum
			camera.CFrame = CFrame.new(M.origin[1], 8, M.origin[3] - 20)
			c:Advance(2)
			local live, spare, built = Museum.Stats()
			expect(built).toBe(#Config.Species.Lines)
			expect(live > 0).toBe(true)
			expect(live <= M.maxModels).toBe(true)
			-- Walk away: every model is parked in the pool (capped), none stay live.
			camera.CFrame = CFrame.new(0, 8, 0)
			c:Advance(2)
			live, spare = Museum.Stats()
			expect(live).toBe(0)
			expect(spare > 0 and spare <= M.maxModels).toBe(true)
			expectClean(c)
		end)

		it("shows every player's best statue on the plaza", function()
			local h = TestKernel.new({ systems = allSystems() })
			local a = h:Join(201, "Ana")
			local info = Config.Species.FormById.blazefang
			h:Section(a, "HallOfFame").entries = {
				{
					appearance = { line = info.line.id, form = "blazefang", stage = 3, rarity = 4 },
					retiredAt = 1,
					rarity = 4,
					element = "ember",
				},
			}
			a = h:Rejoin(a, 5)
			local b = h:Join(202, "Ben")
			local c = ClientHarness.new(h, b)
			local Plaza = c:require(c.clientFolder.Controllers.FamePlaza)
			local camera = c.world.game:GetService("Workspace").CurrentCamera
			camera.CFrame = CFrame.new(Config.Codex.Plaza.origin[1], 8, Config.Codex.Plaza.origin[3])
			c:Advance(3)
			local models, owners = Plaza.Stats()
			expect(owners).toBe(1)
			expect(models).toBe(1)
			local folder = c.world.game:GetService("Workspace"):FindFirstChild("FamePlaza")
			local named = false
			for _, d in folder:GetDescendants() do
				if d:IsA("TextLabel") and d.Text == "Ana" then
					named = true
				end
			end
			expect(named).toBe(true)
			h:Leave(a)
			c:Advance(2)
			models, owners = Plaza.Stats()
			expect(owners).toBe(0)
			expect(models).toBe(0)
			expectClean(c)
		end)
	end)
end
