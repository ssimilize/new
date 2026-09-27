--[[
	ExhibitsClient (update 3.12 · Museum Exhibits): Museum Exhibits through the real client
	(ClientHarness): the Curator desk's "Exhibits" prompt opens the screen, donate a fish and see
	it on display, claim a Fossil Hall reward step, the Codex's Exhibits button, the wing's capped
	displays near the camera, the locked screen before Level 18 and Spanish text.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Exhibits")
	local CFrame = t.Roblox.CFrame

	local Cfg = Config.Exhibits

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

	local function deskPrompt(c)
		for _, d in c.world.workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.ActionText == "Exhibits" then
				return d
			end
		end
		return nil
	end

	local function completeFossil(h, p, fossilId: string)
		local s = h:Section(p, "DigSite")
		s.pieces[fossilId] = {}
		for _, piece in Config.DigSite.Pieces do
			s.pieces[fossilId][piece.id] = true
		end
		h.kernel.Bus:Publish("FossilFound", p, { fossil = fossilId, piece = "tail", complete = true })
	end

	describe("Museum Exhibits", function()
		it("opens from the Curator desk, donates a fish and claims a Fossil Hall step", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, Config.Unlocks.Features.exhibits)
			h:Section(p, "Fishing").fish.bluegill = 1
			p = h:Rejoin(p) -- a fresh join sends the whole save to the client
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local prompt = deskPrompt(c)
			expect(prompt ~= nil).toBe(true)
			expect(prompt:FindFirstAncestor("CuratorWing") ~= nil).toBe(true)
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Exhibits")
			local screen = c:Screen("Exhibits")

			-- The Aquarium: donate the one bluegill.
			c:Click(screen:FindFirstChild("Set_aquarium", true))
			c:Advance(0.3)
			local card = screen:FindFirstChild("Exhibit_bluegill", true)
			expect(card:GetAttribute("Filled")).toBe(false)
			expect(c:HasText("Donate · have 1", card)).toBe(true)
			c:Click(card:FindFirstChild("Donate", true))
			c:Advance(0.5)
			expect(h:Section(p, "Exhibits").filled.aquarium.bluegill).toBe(true)
			expect(h:Section(p, "Fishing").fish.bluegill).toBeNil()
			card = screen:FindFirstChild("Exhibit_bluegill", true)
			expect(card:GetAttribute("Filled")).toBe(true)
			expect(c:HasText("On display", card)).toBe(true)
			expect(c:HasText(string.format("1 / %d on display", #Config.Fishing.Fish), screen)).toBe(true)

			-- The Fossil Hall fills itself; two fossils reach the first step.
			completeFossil(h, p, "raptor")
			completeFossil(h, p, "trihorn")
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("Set_fossils", true))
			c:Advance(0.3)
			expect(screen:FindFirstChild("Exhibit_raptor", true):GetAttribute("Filled")).toBe(true)
			expect(c:HasText("Complete it at the Dig Site", screen:FindFirstChild("Exhibit_longneck", true))).toBe(true)
			local claim = screen:FindFirstChild("ClaimStep", true)
			expect(claim:GetAttribute("Step")).toBe(1)
			local gems0 = h:Section(p, "Currency").gems
			c:Click(claim)
			c:Advance(0.5)
			local gems = Logic.Reward(Config, #Config.DigSite.Fossils, 1)
			expect(h:Section(p, "Currency").gems).toBe(gems0 + gems)
			expect(h:Section(p, "Exhibits").paid.fossils).toBe(1)
			expect(screen:FindFirstChild("Step1", true):GetAttribute("Paid")).toBe(true)
			expect(screen:FindFirstChild("ClaimStep", true):GetAttribute("Step")).toBe(0)
			expectClean(c)
		end)

		it("opens from the Codex screen's Exhibits button", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, Config.Unlocks.Features.exhibits)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local codex = c:Open("Codex")
			c:Advance(0.5)
			c:Click(codex:FindFirstChild("Exhibits", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Exhibits")
			expectClean(c)
		end)

		it("builds capped displays near the camera and none far away", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, Config.Unlocks.Features.exhibits)
			local filled = h:Section(p, "Exhibits").filled
			for _, set in Logic.Sets(Config) do
				filled[set.id] = {}
				for _, item in Logic.Items(Config, set.id) do
					filled[set.id][item.id] = true
				end
			end
			p = h:Rejoin(p, 5)
			local c = ClientHarness.new(h, p)
			local Wing = c:require(c.clientFolder.Controllers.CuratorWing)
			local camera = c.world.game:GetService("Workspace").CurrentCamera
			local W = Config.World.CuratorWing
			camera.CFrame = CFrame.new(W.center[1], 8, W.center[2])
			c:Advance(2)
			local live, built = Wing.Stats()
			expect(built > 20).toBe(true)
			expect(live > 0).toBe(true)
			expect(live <= Cfg.Wing.maxModels).toBe(true)
			camera.CFrame = CFrame.new(0, 8, 0)
			c:Advance(2)
			live = Wing.Stats()
			expect(live).toBe(0)
			expectClean(c)
		end)

		it("shows the screen locked before Level 18", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Exhibits")
			c:Advance(0.5)
			expect(c:HasText(string.format("Unlocks at Ranch Level %d", Config.Unlocks.Features.exhibits), screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the screen in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, Config.Unlocks.Features.exhibits)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			c:Open("Exhibits")
			c:Advance(0.5)
			expect(c:HasText("Exposiciones del museo")).toBe(true)
			expectClean(c)
		end)
	end)
end
